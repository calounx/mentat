#!/usr/bin/env bash
#
# Simple Upgrade State Machine Tests
#
# Streamlined test suite that avoids re-sourcing issues
#
# Author: Observability Stack Team
# License: MIT

set -euo pipefail

# Test configuration
readonly TEST_DIR="/tmp/upgrade-state-tests-$$"

# Set up environment BEFORE sourcing
export UPGRADE_STATE_DIR="${TEST_DIR}/state"
export UPGRADE_HISTORY_DIR="${UPGRADE_STATE_DIR}/history"
export UPGRADE_BACKUPS_DIR="${UPGRADE_STATE_DIR}/backups"
export UPGRADE_STATE_FILE="${UPGRADE_STATE_DIR}/state.json"
export UPGRADE_LOCK_FILE="${UPGRADE_STATE_DIR}/upgrade.lock"
export UPGRADE_TEMP_DIR="${UPGRADE_STATE_DIR}/tmp"

# Source library once
readonly LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib" && pwd)"
# shellcheck source=../scripts/lib/upgrade-state.sh
source "${LIB_DIR}/upgrade-state.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#######################################
# Print test result
#######################################
print_test_result() {
    local test_name="$1"
    local result="$2"
    local error_msg="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ $result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ${test_name}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} ${test_name}"
        if [[ -n "$error_msg" ]]; then
            echo -e "  ${RED}Error: ${error_msg}${NC}"
        fi
    fi
}

#######################################
# Setup for each test
#######################################
setup() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    upgrade_state_init_dirs >/dev/null 2>&1
}

#######################################
# Cleanup after each test
#######################################
cleanup() {
    upgrade_lock_release 2>/dev/null || true
    rm -rf "$TEST_DIR"
}

echo -e "${BLUE}=== Upgrade State Machine Test Suite ===${NC}\n"
echo -e "${YELLOW}Running Tests:${NC}"

# Test 1: State initialization
setup
if upgrade_id=$(upgrade_state_init 2>&1); then
    if [[ -f "$UPGRADE_STATE_FILE" ]] && [[ "$(jq -r '.current_state' "$UPGRADE_STATE_FILE")" == "IDLE" ]]; then
        print_test_result "State initialization" 0
    else
        print_test_result "State initialization" 1 "Invalid initial state"
    fi
else
    print_test_result "State initialization" 1 "Init failed"
fi
cleanup

# Test 2: State transitions
setup
upgrade_state_init >/dev/null 2>&1
error=""
for transition in "PLANNING" "BACKING_UP" "UPGRADING" "VALIDATING" "COMPLETED"; do
    if ! upgrade_state_set "$transition" 2>/dev/null; then
        error="Failed to set $transition"
        break
    fi
    if [[ "$(upgrade_state_get_current)" != "$transition" ]]; then
        error="State mismatch for $transition"
        break
    fi
done
if [[ -z "$error" ]]; then
    print_test_result "Valid state transitions" 0
else
    print_test_result "Valid state transitions" 1 "$error"
fi
cleanup

# Test 3: Invalid transitions
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_state_set "VALIDATING" >/dev/null 2>&1
upgrade_state_set "COMPLETED" >/dev/null 2>&1
if upgrade_state_set "UPGRADING" 2>/dev/null; then
    print_test_result "Invalid transitions blocked" 1 "COMPLETED→UPGRADING allowed"
else
    print_test_result "Invalid transitions blocked" 0
fi
cleanup

# Test 4: Phase management
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
if upgrade_phase_start "exporters" 2>&1 && \
   [[ "$(jq -r '.current_phase' "$UPGRADE_STATE_FILE")" == "exporters" ]] && \
   upgrade_phase_complete "exporters" 2>&1 && \
   [[ "$(jq -r '.phases.exporters.state' "$UPGRADE_STATE_FILE")" == "COMPLETED" ]]; then
    print_test_result "Phase management" 0
else
    print_test_result "Phase management" 1 "Phase operations failed"
fi
cleanup

# Test 5: Component tracking
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_phase_start "exporters" >/dev/null 2>&1
if upgrade_component_start "node_exporter" "1.7.0" "1.9.1" 2>&1 && \
   [[ "$(jq -r '.phases.exporters.components.node_exporter.state' "$UPGRADE_STATE_FILE")" == "UPGRADING" ]] && \
   upgrade_component_complete "node_exporter" 2>&1 && \
   [[ "$(jq -r '.phases.exporters.components.node_exporter.state' "$UPGRADE_STATE_FILE")" == "COMPLETED" ]]; then
    print_test_result "Component tracking" 0
else
    print_test_result "Component tracking" 1 "Component operations failed"
fi
cleanup

# Test 6: Idempotency
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_phase_start "exporters" >/dev/null 2>&1
upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null 2>&1
upgrade_component_complete "node_exporter" >/dev/null 2>&1
if upgrade_component_is_upgraded "node_exporter" 2>&1; then
    upgrade_component_start "nginx_exporter" "1.1.0" "1.5.1" >/dev/null 2>&1
    if ! upgrade_component_is_upgraded "nginx_exporter" 2>&1; then
        print_test_result "Idempotency checks" 0
    else
        print_test_result "Idempotency checks" 1 "In-progress detected as completed"
    fi
else
    print_test_result "Idempotency checks" 1 "Completed not detected"
fi
cleanup

# Test 7: Crash recovery
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_phase_start "exporters" >/dev/null 2>&1
if upgrade_can_resume 2>&1 && \
   [[ "$(upgrade_get_resume_point | jq -r '.state')" == "UPGRADING" ]] && \
   upgrade_resume 2>&1; then
    print_test_result "Crash recovery" 0
else
    print_test_result "Crash recovery" 1 "Resume failed"
fi
cleanup

# Test 8: Lock acquisition
setup
if upgrade_lock_acquire 2>&1 && \
   upgrade_lock_is_held 2>&1 && \
   upgrade_lock_release 2>&1 && \
   ! upgrade_lock_is_held 2>&1; then
    print_test_result "Lock acquisition/release" 0
else
    print_test_result "Lock acquisition/release" 1 "Lock operations failed"
fi
cleanup

# Test 9: Rollback tracking
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_phase_start "exporters" >/dev/null 2>&1
upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null 2>&1
backup_path="/tmp/test-backup.tar.gz"
if upgrade_mark_rollback_point "node_exporter" "$backup_path" 2>&1 && \
   [[ "$(upgrade_get_rollback_info | jq -r '.rollback_available')" == "true" ]]; then
    print_test_result "Rollback tracking" 0
else
    print_test_result "Rollback tracking" 1 "Rollback operations failed"
fi
cleanup

# Test 10: Progress calculation
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_phase_start "exporters" >/dev/null 2>&1
upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null 2>&1
upgrade_component_start "nginx_exporter" "1.1.0" "1.5.1" >/dev/null 2>&1
upgrade_component_start "mysqld_exporter" "0.14.0" "0.16.1" >/dev/null 2>&1
upgrade_component_start "phpfpm_exporter" "2.2.0" "2.3.1" >/dev/null 2>&1
upgrade_component_complete "node_exporter" >/dev/null 2>&1
upgrade_component_complete "nginx_exporter" >/dev/null 2>&1
progress=$(upgrade_get_progress_percent)
if [[ "$progress" == "50" ]]; then
    print_test_result "Progress calculation" 0
else
    print_test_result "Progress calculation" 1 "Expected 50%, got ${progress}%"
fi
cleanup

# Test 11: History tracking
setup
upgrade_id=$(upgrade_state_init 2>&1)
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_state_set "VALIDATING" >/dev/null 2>&1
upgrade_state_set "COMPLETED" >/dev/null 2>&1
if upgrade_save_to_history 2>&1 && \
   [[ -f "${UPGRADE_HISTORY_DIR}/${upgrade_id}.json" ]]; then
    print_test_result "History tracking" 0
else
    print_test_result "History tracking" 1 "History save failed"
fi
cleanup

# Test 12: Component failure
setup
upgrade_state_init >/dev/null 2>&1
upgrade_state_set "PLANNING" >/dev/null 2>&1
upgrade_state_set "BACKING_UP" >/dev/null 2>&1
upgrade_state_set "UPGRADING" >/dev/null 2>&1
upgrade_phase_start "exporters" >/dev/null 2>&1
upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null 2>&1
upgrade_component_fail "node_exporter" "Download failed" >/dev/null 2>&1
if [[ "$(jq -r '.phases.exporters.components.node_exporter.state' "$UPGRADE_STATE_FILE")" == "FAILED" ]] && \
   [[ "$(jq -r '.phases.exporters.components.node_exporter.last_error' "$UPGRADE_STATE_FILE")" == "Download failed" ]]; then
    print_test_result "Component failure tracking" 0
else
    print_test_result "Component failure tracking" 1 "Failure not recorded"
fi
cleanup

# Test 13: In-progress detection
setup
upgrade_state_init >/dev/null 2>&1
if upgrade_is_in_progress 2>&1; then
    print_test_result "In-progress detection" 1 "IDLE detected as in-progress"
else
    upgrade_state_set "PLANNING" >/dev/null 2>&1
    upgrade_state_set "BACKING_UP" >/dev/null 2>&1
    upgrade_state_set "UPGRADING" >/dev/null 2>&1
    if upgrade_is_in_progress 2>&1; then
        print_test_result "In-progress detection" 0
    else
        print_test_result "In-progress detection" 1 "UPGRADING not detected"
    fi
fi
cleanup

# Print summary
echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "Total tests run: ${TESTS_RUN}"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi
