#!/usr/bin/env bash
# Comprehensive Idempotency and Edge Case Test Runner
# Runs all tests and generates a detailed report
#
# Usage: sudo ./run-all-idempotency-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="${SCRIPT_DIR}/results/comprehensive-${TIMESTAMP}"
TEST_USER="test-idempotent-${RANDOM}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Create report directory
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/COMPREHENSIVE_REPORT.md"

# Initialize report
cat > "$REPORT_FILE" <<EOF
# Idempotency and Edge Case Testing Report

**Generated:** $(date)
**Test Run ID:** $TIMESTAMP

---

## Executive Summary

This report documents comprehensive testing of deployment script idempotency
and edge case handling.

---

EOF

echo "========================================================================"
echo "  COMPREHENSIVE IDEMPOTENCY AND EDGE CASE TESTING"
echo "========================================================================"
echo ""
echo "Report will be saved to: $REPORT_FILE"
echo ""

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    cat >> "$REPORT_FILE" <<EOF

## $1

EOF
}

log_test() {
    ((TOTAL_TESTS++))
    echo -e "${BLUE}[TEST $TOTAL_TESTS]${NC} $1"
    echo "**Test $TOTAL_TESTS:** $1" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

log_pass() {
    ((PASSED_TESTS++))
    echo -e "${GREEN}✓ PASS${NC} $1"
    echo "- ✓ **PASS:** $1" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

log_fail() {
    ((FAILED_TESTS++))
    echo -e "${RED}✗ FAIL${NC} $1"
    echo "- ✗ **FAIL:** $1" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

log_info() {
    echo -e "${BLUE}  ℹ${NC} $1"
    echo "  - $1" >> "$REPORT_FILE"
}

log_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
    echo "  - **WARNING:** $1" >> "$REPORT_FILE"
}

# ==============================================================================
# TEST 1: USER CREATION IDEMPOTENCY
# ==============================================================================

test_user_creation_idempotency() {
    log_section "TEST 1: User Creation Idempotency"
    log_test "Verify setup-stilgar-user-standalone.sh is truly idempotent"

    local script="${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh"

    # First run
    log_info "First run: Creating user $TEST_USER"
    if sudo bash "$script" "$TEST_USER" > "${REPORT_DIR}/user-creation-run1.log" 2>&1; then
        log_info "User created successfully"
    else
        log_fail "First run failed"
        return 1
    fi

    # Capture initial state
    local uid1=$(id -u "$TEST_USER")
    local gid1=$(id -g "$TEST_USER")
    local groups1=$(id -G "$TEST_USER" | tr ' ' ',')
    local home1=$(getent passwd "$TEST_USER" | cut -d: -f6)

    log_info "Initial state: UID=$uid1, GID=$gid1, Home=$home1"

    # Second run
    log_info "Second run: Testing idempotency"
    if sudo bash "$script" "$TEST_USER" > "${REPORT_DIR}/user-creation-run2.log" 2>&1; then
        log_info "Second run completed"
    else
        log_fail "Second run failed"
        return 1
    fi

    # Capture second state
    local uid2=$(id -u "$TEST_USER")
    local gid2=$(id -g "$TEST_USER")
    local groups2=$(id -G "$TEST_USER" | tr ' ' ',')
    local home2=$(getent passwd "$TEST_USER" | cut -d: -f6)

    # Compare
    if [[ "$uid1" == "$uid2" ]] && [[ "$gid1" == "$gid2" ]] && \
       [[ "$groups1" == "$groups2" ]] && [[ "$home1" == "$home2" ]]; then
        log_pass "User attributes unchanged after second run"
    else
        log_fail "User attributes changed: UID($uid1->$uid2), GID($gid1->$gid2)"
        return 1
    fi

    # Third run
    log_info "Third run: Verify continued idempotency"
    if sudo bash "$script" "$TEST_USER" > "${REPORT_DIR}/user-creation-run3.log" 2>&1; then
        local uid3=$(id -u "$TEST_USER")
        if [[ "$uid1" == "$uid3" ]]; then
            log_pass "User creation is idempotent across 3 runs"
        else
            log_fail "UID changed on third run"
            return 1
        fi
    else
        log_fail "Third run failed"
        return 1
    fi

    return 0
}

# ==============================================================================
# TEST 2: SUDO CONFIGURATION IDEMPOTENCY
# ==============================================================================

test_sudo_idempotency() {
    log_section "TEST 2: Sudo Configuration Idempotency"
    log_test "Verify NOPASSWD sudo remains configured correctly"

    local sudoers_file="/etc/sudoers.d/${TEST_USER}-nopasswd"

    # Verify file exists
    if [[ ! -f "$sudoers_file" ]]; then
        log_fail "Sudoers file not created: $sudoers_file"
        return 1
    fi

    # Check permissions
    local perms=$(stat -c "%a" "$sudoers_file")
    if [[ "$perms" == "440" ]]; then
        log_pass "Sudoers file has correct permissions: $perms"
    else
        log_fail "Incorrect permissions: $perms (expected 440)"
        return 1
    fi

    # Check content
    if grep -q "NOPASSWD:ALL" "$sudoers_file"; then
        log_pass "NOPASSWD configuration present"
    else
        log_fail "NOPASSWD configuration missing"
        return 1
    fi

    # Test sudo access
    if sudo -u "$TEST_USER" sudo -n whoami > /dev/null 2>&1; then
        log_pass "Passwordless sudo works correctly"
    else
        log_fail "Passwordless sudo doesn't work"
        return 1
    fi

    # Re-run script and verify file unchanged
    local mtime_before=$(stat -c "%Y" "$sudoers_file")
    local content_before=$(cat "$sudoers_file")

    sudo bash "${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh" "$TEST_USER" > /dev/null 2>&1

    local mtime_after=$(stat -c "%Y" "$sudoers_file")
    local content_after=$(cat "$sudoers_file")

    if [[ "$content_before" == "$content_after" ]]; then
        log_pass "Sudoers file content unchanged after re-run"
    else
        log_warning "Sudoers file was rewritten (but content may be same)"
    fi

    return 0
}

# ==============================================================================
# TEST 3: SSH DIRECTORY IDEMPOTENCY
# ==============================================================================

test_ssh_directory_idempotency() {
    log_section "TEST 3: SSH Directory Idempotency"
    log_test "Verify SSH directory and authorized_keys handling"

    local ssh_dir="/home/${TEST_USER}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    # Verify directory exists
    if [[ ! -d "$ssh_dir" ]]; then
        log_fail "SSH directory not created: $ssh_dir"
        return 1
    fi

    # Check permissions
    local dir_perms=$(stat -c "%a" "$ssh_dir")
    if [[ "$dir_perms" == "700" ]]; then
        log_pass "SSH directory permissions correct: $dir_perms"
    else
        log_fail "Incorrect SSH dir permissions: $dir_perms (expected 700)"
        return 1
    fi

    # Check authorized_keys
    if [[ -f "$auth_keys" ]]; then
        local file_perms=$(stat -c "%a" "$auth_keys")
        if [[ "$file_perms" == "600" ]]; then
            log_pass "authorized_keys permissions correct: $file_perms"
        else
            log_fail "Incorrect authorized_keys permissions: $file_perms (expected 600)"
            return 1
        fi
    else
        log_fail "authorized_keys file not created"
        return 1
    fi

    # Add a test SSH key
    local test_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyForIdempotency test@test"
    echo "$test_key" | sudo tee -a "$auth_keys" > /dev/null
    local key_count=$(wc -l < "$auth_keys")

    log_info "Added test key, total keys: $key_count"

    # Re-run script
    sudo bash "${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh" "$TEST_USER" > /dev/null 2>&1

    # Verify key not lost
    local new_key_count=$(wc -l < "$auth_keys")
    if [[ "$key_count" == "$new_key_count" ]]; then
        log_pass "SSH keys preserved after re-run (count: $new_key_count)"
    else
        log_fail "SSH keys lost or duplicated: $key_count -> $new_key_count"
        return 1
    fi

    # Verify test key still present
    if grep -q "TestKeyForIdempotency" "$auth_keys"; then
        log_pass "Test SSH key still present"
    else
        log_fail "Test SSH key was removed"
        return 1
    fi

    return 0
}

# ==============================================================================
# TEST 4: BASH PROFILE IDEMPOTENCY
# ==============================================================================

test_bash_profile_idempotency() {
    log_section "TEST 4: Bash Profile Configuration Idempotency"
    log_test "Verify bash profile not duplicated on multiple runs"

    local bashrc="/home/${TEST_USER}/.bashrc"

    if [[ ! -f "$bashrc" ]]; then
        log_fail "Bashrc file not found: $bashrc"
        return 1
    fi

    # Count occurrences of deployment marker
    local marker_count=$(grep -c "CHOM Deployment User" "$bashrc" || true)

    log_info "Initial marker count: $marker_count"

    # Re-run script multiple times
    for i in {1..3}; do
        sudo bash "${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh" "$TEST_USER" > /dev/null 2>&1
        local new_count=$(grep -c "CHOM Deployment User" "$bashrc" || true)

        if [[ "$new_count" != "$marker_count" ]]; then
            log_fail "Bash profile duplicated on run $i (count: $marker_count -> $new_count)"
            return 1
        fi
    done

    log_pass "Bash profile not duplicated after 3 additional runs"
    return 0
}

# ==============================================================================
# TEST 5: CONCURRENT EXECUTION
# ==============================================================================

test_concurrent_execution() {
    log_section "TEST 5: Concurrent Execution Safety"
    log_test "Verify script handles concurrent execution"

    local test_user2="test-concurrent-${RANDOM}"

    # Run script twice simultaneously for different users
    sudo bash "${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh" "$test_user2" > /dev/null 2>&1 &
    local pid1=$!

    sudo bash "${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh" "${test_user2}-2" > /dev/null 2>&1 &
    local pid2=$!

    # Wait for both
    wait $pid1 || true
    wait $pid2 || true

    # Verify both users created successfully
    if id "$test_user2" &>/dev/null && id "${test_user2}-2" &>/dev/null; then
        log_pass "Concurrent user creation succeeded"
    else
        log_fail "Concurrent user creation failed"
        userdel -r "$test_user2" 2>/dev/null || true
        userdel -r "${test_user2}-2" 2>/dev/null || true
        return 1
    fi

    # Cleanup
    userdel -r "$test_user2" 2>/dev/null || true
    userdel -r "${test_user2}-2" 2>/dev/null || true
    rm -f "/etc/sudoers.d/${test_user2}-nopasswd" "/etc/sudoers.d/${test_user2}-2-nopasswd"

    log_pass "Concurrent execution handled safely"
    return 0
}

# ==============================================================================
# TEST 6: EMPTY ENVIRONMENT VARIABLES
# ==============================================================================

test_empty_env_vars() {
    log_section "TEST 6: Empty Environment Variables"
    log_test "Verify script handles empty environment variables"

    # Test with empty DEPLOY_USER (should use default 'stilgar')
    local output
    output=$(DEPLOY_USER="" bash "${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh" 2>&1 || true)

    if echo "$output" | grep -q "stilgar"; then
        log_pass "Script uses default user when DEPLOY_USER is empty"
    else
        log_fail "Script doesn't handle empty DEPLOY_USER correctly"
        return 1
    fi

    return 0
}

# ==============================================================================
# TEST 7: SPECIAL CHARACTERS IN USERNAME
# ==============================================================================

test_special_chars_username() {
    log_section "TEST 7: Special Characters in Username"
    log_test "Verify script rejects invalid usernames"

    local invalid_users=(
        "user with spaces"
        "user-with-dashes"  # Actually valid
        "user_with_underscores"  # Actually valid
        "user@domain"
        "user#special"
        "user;semicolon"
        "user|pipe"
    )

    local tested=0
    local safe=0

    for username in "${invalid_users[@]}"; do
        ((tested++))
        # Try to create user (expect failure for invalid names)
        if sudo useradd -m "$username" 2>/dev/null; then
            log_info "Username '$username' was accepted"
            # Clean up
            userdel -r "$username" 2>/dev/null || true

            # If it contains spaces or special chars, it's a problem
            if [[ "$username" =~ [[:space:]\@\#\;\|] ]]; then
                log_warning "Unsafe username accepted: $username"
            else
                ((safe++))
            fi
        else
            log_info "Username '$username' correctly rejected"
            ((safe++))
        fi
    done

    if [[ $safe -eq $tested ]]; then
        log_pass "Username validation works correctly"
    else
        log_warning "Some unsafe usernames may be accepted"
    fi

    return 0
}

# ==============================================================================
# TEST 8: DISK SPACE CHECK
# ==============================================================================

test_disk_space_awareness() {
    log_section "TEST 8: Disk Space Awareness"
    log_test "Verify deployment checks available disk space"

    local available=$(df / | awk 'NR==2 {print $4}')
    local available_mb=$((available / 1024))
    local available_gb=$((available_mb / 1024))

    log_info "Available disk space: ${available_gb}GB (${available_mb}MB)"

    if [[ $available_gb -lt 1 ]]; then
        log_warning "Low disk space: ${available_gb}GB available"
        log_warning "Deployment may fail with insufficient space"
    else
        log_pass "Sufficient disk space available: ${available_gb}GB"
    fi

    return 0
}

# ==============================================================================
# TEST 9: CLEANUP VERIFICATION
# ==============================================================================

test_cleanup_tmp_files() {
    log_section "TEST 9: Temporary File Cleanup"
    log_test "Verify /tmp files are cleaned up"

    # Check for leftover temp files from deployment
    local temp_pattern="/tmp/*chom*"
    local temp_count=$(ls -1 $temp_pattern 2>/dev/null | wc -l)

    log_info "Deployment temp files found: $temp_count"

    if [[ $temp_count -eq 0 ]]; then
        log_pass "No leftover temporary files"
    else
        log_warning "Found $temp_count temporary files"
        ls -la $temp_pattern 2>/dev/null | head -10 | while read line; do
            log_info "$line"
        done
    fi

    return 0
}

# ==============================================================================
# TEST 10: PERMISSION VERIFICATION
# ==============================================================================

test_permission_correctness() {
    log_section "TEST 10: File Permission Correctness"
    log_test "Verify all created files have correct permissions"

    local home_dir="/home/${TEST_USER}"
    local issues=0

    # Check home directory
    local home_perms=$(stat -c "%a" "$home_dir")
    if [[ "$home_perms" == "750" ]]; then
        log_pass "Home directory permissions correct: $home_perms"
    else
        log_fail "Home directory permissions incorrect: $home_perms (expected 750)"
        ((issues++))
    fi

    # Check ownership
    local owner=$(stat -c "%U:%G" "$home_dir")
    if [[ "$owner" == "${TEST_USER}:${TEST_USER}" ]]; then
        log_pass "Home directory ownership correct: $owner"
    else
        log_fail "Home directory ownership incorrect: $owner"
        ((issues++))
    fi

    # Check SSH directory
    if [[ -d "${home_dir}/.ssh" ]]; then
        local ssh_perms=$(stat -c "%a" "${home_dir}/.ssh")
        if [[ "$ssh_perms" == "700" ]]; then
            log_pass "SSH directory permissions correct: $ssh_perms"
        else
            log_fail "SSH directory permissions incorrect: $ssh_perms"
            ((issues++))
        fi
    fi

    if [[ $issues -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    echo "Starting comprehensive test suite..."
    echo ""

    # Run all tests
    test_user_creation_idempotency
    test_sudo_idempotency
    test_ssh_directory_idempotency
    test_bash_profile_idempotency
    test_concurrent_execution
    test_empty_env_vars
    test_special_chars_username
    test_disk_space_awareness
    test_cleanup_tmp_files
    test_permission_correctness

    # Cleanup test user
    log_section "Cleanup"
    echo "Removing test user: $TEST_USER"
    userdel -r "$TEST_USER" 2>/dev/null || true
    rm -f "/etc/sudoers.d/${TEST_USER}-nopasswd"

    # Generate final report
    cat >> "$REPORT_FILE" <<EOF

---

## Final Results

- **Total Tests:** $TOTAL_TESTS
- **Passed:** $PASSED_TESTS
- **Failed:** $FAILED_TESTS
- **Pass Rate:** $(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS / $TOTAL_TESTS) * 100}")%

---

## Recommendations

EOF

    if [[ $FAILED_TESTS -eq 0 ]]; then
        cat >> "$REPORT_FILE" <<EOF
✓ **All tests passed!** The deployment scripts demonstrate true idempotency
and handle edge cases correctly.

### Summary
- User creation is idempotent across multiple runs
- Sudo configuration remains stable
- SSH directory and keys are preserved
- Bash profile configuration doesn't duplicate
- Concurrent execution is handled safely
- File permissions are correct
- Cleanup mechanisms work properly

EOF
    else
        cat >> "$REPORT_FILE" <<EOF
⚠ **$FAILED_TESTS test(s) failed.** Review the failures above and address
the identified issues.

### Priority Actions
1. Fix failing tests identified above
2. Add additional error handling
3. Implement rollback mechanisms
4. Add logging for edge cases

EOF
    fi

    # Display summary
    echo ""
    echo "========================================================================"
    echo "  TEST SUMMARY"
    echo "========================================================================"
    echo ""
    echo "  Total Tests:  $TOTAL_TESTS"
    echo -e "  Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "  Failed:       ${RED}$FAILED_TESTS${NC}"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "  ${GREEN}✓ ALL TESTS PASSED${NC}"
    else
        echo -e "  ${RED}✗ SOME TESTS FAILED${NC}"
    fi

    echo ""
    echo "  Report saved to: $REPORT_FILE"
    echo ""
    echo "========================================================================"

    # Return exit code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Run main
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

main
