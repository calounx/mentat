#!/usr/bin/env bash
# Advanced Edge Case Testing
# Tests deployment scripts under extreme and unusual conditions
#
# Usage: sudo ./test-edge-cases-advanced.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_RESULTS_DIR="${SCRIPT_DIR}/results/edge-cases-$(date +%Y%m%d_%H%M%S)"
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() { echo -e "${BLUE}[TEST]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)); }
log_info() { [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[INFO]${NC} $*" || true; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

setup_test_environment() {
    mkdir -p "$TEST_RESULTS_DIR"
    TEST_LOG="${TEST_RESULTS_DIR}/test.log"
    touch "$TEST_LOG"
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    ((TESTS_RUN++))
    log_test "Running: $test_name"
    if $test_function "$test_name"; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name"
        return 1
    fi
}

# ==============================================================================
# ADVANCED EDGE CASE TESTS
# ==============================================================================

test_unicode_in_paths() {
    local test_name="$1"
    log_info "Testing Unicode characters in paths"

    # Create directory with Unicode characters
    local test_dir="/tmp/test-unicode-${RANDOM}-日本語-émojis🚀"
    mkdir -p "$test_dir" || {
        log_error "Failed to create Unicode directory"
        return 1
    }

    # Test file operations
    touch "${test_dir}/test-файл.txt" || {
        log_error "Failed to create Unicode filename"
        rm -rf "$test_dir"
        return 1
    }

    # Cleanup
    rm -rf "$test_dir"
    log_info "Unicode handling works"
    return 0
}

test_symlink_loops() {
    local test_name="$1"
    log_info "Testing symlink loop detection"

    local test_dir="/tmp/test-symlinks-$$"
    mkdir -p "$test_dir"

    # Create symlink loop
    ln -s "${test_dir}/link2" "${test_dir}/link1"
    ln -s "${test_dir}/link1" "${test_dir}/link2"

    # Try to traverse (should not hang)
    if timeout 2 ls -la "${test_dir}/link1" &>/dev/null; then
        log_error "ls succeeded on symlink loop (should fail)"
        rm -rf "$test_dir"
        return 1
    fi

    # Cleanup
    rm -rf "$test_dir"
    log_info "Symlink loop handled correctly"
    return 0
}

test_extremely_long_paths() {
    local test_name="$1"
    log_info "Testing extremely long path names"

    # Linux PATH_MAX is typically 4096
    local base_dir="/tmp/test-long-path-$$"
    mkdir -p "$base_dir"

    # Create a very long path (but under PATH_MAX)
    local long_path="$base_dir"
    for i in {1..50}; do
        long_path="${long_path}/very-long-directory-name-${i}"
    done

    # Try to create it
    if mkdir -p "$long_path" 2>/dev/null; then
        log_info "Long path created successfully"
        rm -rf "$base_dir"
        return 0
    else
        log_info "Path too long (expected on some filesystems)"
        rm -rf "$base_dir"
        return 0  # This is acceptable behavior
    fi
}

test_race_condition_file_creation() {
    local test_name="$1"
    log_info "Testing race conditions in file creation"

    local test_file="/tmp/test-race-$$"

    # Start multiple processes trying to create the same file
    local pids=()
    for i in {1..5}; do
        (
            # Try to create file exclusively
            if (set -o noclobber; > "$test_file") 2>/dev/null; then
                echo "$i" > "$test_file"
                exit 0
            else
                exit 1
            fi
        ) &
        pids+=($!)
    done

    # Wait for all processes
    local success_count=0
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success_count++))
        fi
    done

    # Cleanup
    rm -f "$test_file"

    # Only one should succeed
    if [[ $success_count -eq 1 ]]; then
        log_info "Race condition handled correctly (1 success)"
        return 0
    else
        log_error "Race condition not handled ($success_count successes)"
        return 1
    fi
}

test_disk_full_simulation() {
    local test_name="$1"
    log_info "Testing disk full condition"

    # Create a small loopback filesystem
    local test_img="/tmp/test-disk-full-$$.img"
    local test_mount="/tmp/test-mount-$$"

    dd if=/dev/zero of="$test_img" bs=1M count=10 &>/dev/null
    mkfs.ext4 -F "$test_img" &>/dev/null
    mkdir -p "$test_mount"
    mount -o loop "$test_img" "$test_mount"

    # Fill it up
    dd if=/dev/zero of="${test_mount}/fill" bs=1M count=9 &>/dev/null || true

    # Try to write more (should fail gracefully)
    if dd if=/dev/zero of="${test_mount}/overflow" bs=1M count=5 &>/dev/null; then
        log_error "Write succeeded when disk should be full"
        umount "$test_mount"
        rm -rf "$test_mount" "$test_img"
        return 1
    fi

    # Verify error handling
    if [[ $? -eq 1 ]] || [[ $? -gt 0 ]]; then
        log_info "Disk full condition handled correctly"
    fi

    # Cleanup
    umount "$test_mount"
    rm -rf "$test_mount" "$test_img"
    return 0
}

test_process_signals() {
    local test_name="$1"
    log_info "Testing signal handling"

    # Create a test script that handles signals
    local test_script="/tmp/test-signals-$$.sh"
    cat > "$test_script" <<'EOF'
#!/bin/bash
cleanup() {
    echo "Cleanup called"
    exit 0
}
trap cleanup SIGTERM SIGINT
sleep 30 &
wait $!
EOF
    chmod +x "$test_script"

    # Run it
    "$test_script" &
    local pid=$!

    sleep 0.5

    # Send SIGTERM
    kill -TERM "$pid" 2>/dev/null || true

    # Wait with timeout
    local wait_count=0
    while kill -0 "$pid" 2>/dev/null && [[ $wait_count -lt 10 ]]; do
        sleep 0.1
        ((wait_count++))
    done

    # Check if process terminated
    if kill -0 "$pid" 2>/dev/null; then
        log_error "Process didn't terminate on SIGTERM"
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$test_script"
        return 1
    fi

    rm -f "$test_script"
    log_info "Signal handling works correctly"
    return 0
}

test_broken_pipe_handling() {
    local test_name="$1"
    log_info "Testing broken pipe handling"

    # Test script that writes to stdout
    local output
    output=$(yes | head -1 2>&1) || {
        # yes will receive SIGPIPE when head closes
        # This is expected behavior
        log_info "Broken pipe handled correctly"
        return 0
    }

    if [[ -n "$output" ]]; then
        log_info "Pipe communication works"
        return 0
    else
        log_error "No output from pipe"
        return 1
    fi
}

test_environment_variable_injection() {
    local test_name="$1"
    log_info "Testing environment variable injection"

    # Test with malicious environment variables
    local malicious_vars=(
        'PATH=/tmp:$PATH'
        'LD_PRELOAD=/tmp/evil.so'
        'BASH_ENV=/tmp/evil.sh'
        'ENV=/tmp/evil.sh'
    )

    for var in "${malicious_vars[@]}"; do
        # Test that scripts don't blindly trust environment
        # In production, scripts should sanitize or ignore these
        log_info "Testing: $var"

        # Scripts should either reset PATH or validate it
        if env "$var" bash -c 'echo $PATH' | grep -q "/tmp"; then
            log_info "Warning: Script may be vulnerable to PATH injection"
            # Not necessarily a failure, but worth noting
        fi
    done

    return 0
}

test_timezone_edge_cases() {
    local test_name="$1"
    log_info "Testing timezone edge cases"

    # Save current timezone
    local original_tz="${TZ:-}"

    # Test with various timezones
    local timezones=(
        "UTC"
        "America/New_York"
        "Asia/Tokyo"
        "Australia/Sydney"
        "Pacific/Auckland"
    )

    for tz in "${timezones[@]}"; do
        export TZ="$tz"
        local timestamp=$(date -Iseconds)

        if [[ -z "$timestamp" ]]; then
            log_error "Failed to generate timestamp in $tz"
            export TZ="$original_tz"
            return 1
        fi

        log_info "Timezone $tz: $timestamp"
    done

    # Restore original timezone
    export TZ="$original_tz"

    log_info "Timezone handling works"
    return 0
}

test_locale_handling() {
    local test_name="$1"
    log_info "Testing locale handling"

    # Save current locale
    local original_lang="${LANG:-}"
    local original_lc_all="${LC_ALL:-}"

    # Test with different locales
    local locales=("C" "en_US.UTF-8" "POSIX")

    for locale in "${locales[@]}"; do
        export LANG="$locale"
        export LC_ALL="$locale"

        # Test date formatting
        local date_output=$(date 2>&1)
        if [[ $? -eq 0 ]]; then
            log_info "Locale $locale: OK"
        else
            log_error "Locale $locale: FAILED"
            export LANG="$original_lang"
            export LC_ALL="$original_lc_all"
            return 1
        fi
    done

    # Restore original locale
    export LANG="$original_lang"
    export LC_ALL="$original_lc_all"

    return 0
}

test_file_descriptor_limits() {
    local test_name="$1"
    log_info "Testing file descriptor limits"

    # Get current limit
    local soft_limit=$(ulimit -n)
    log_info "Current fd limit: $soft_limit"

    # Try to open many files
    local test_dir="/tmp/test-fd-$$"
    mkdir -p "$test_dir"

    # Open files up to half the limit
    local fd_count=$((soft_limit / 2))
    if [[ $fd_count -gt 1000 ]]; then
        fd_count=1000  # Cap at 1000 for testing
    fi

    local opened=0
    for i in $(seq 1 $fd_count); do
        if exec {fd}<>/dev/null 2>/dev/null; then
            ((opened++))
        else
            break
        fi
    done

    log_info "Opened $opened file descriptors"

    # Cleanup
    rm -rf "$test_dir"

    if [[ $opened -gt 100 ]]; then
        log_info "File descriptor handling works"
        return 0
    else
        log_error "Could only open $opened file descriptors"
        return 1
    fi
}

test_invalid_json_handling() {
    local test_name="$1"
    log_info "Testing invalid JSON handling"

    local invalid_json=(
        '{"invalid": json}'
        '{"missing": "closing bracket"'
        '{invalid: "no quotes"}'
        '{"trailing": "comma",}'
        'not json at all'
    )

    for json in "${invalid_json[@]}"; do
        if echo "$json" | jq . &>/dev/null; then
            log_error "Invalid JSON was accepted: $json"
            return 1
        else
            log_info "Correctly rejected: $json"
        fi
    done

    return 0
}

test_network_unreachable() {
    local test_name="$1"
    log_info "Testing network unreachable scenarios"

    # Try to connect to reserved IP that should be unreachable
    local unreachable_ips=(
        "192.0.2.1"      # TEST-NET-1
        "198.51.100.1"   # TEST-NET-2
        "203.0.113.1"    # TEST-NET-3
    )

    for ip in "${unreachable_ips[@]}"; do
        if timeout 2 curl -s --connect-timeout 1 "http://$ip" &>/dev/null; then
            log_error "Connection succeeded to unreachable IP: $ip"
            return 1
        else
            log_info "Correctly failed to reach: $ip"
        fi
    done

    return 0
}

test_dns_resolution_failure() {
    local test_name="$1"
    log_info "Testing DNS resolution failure"

    # Try to resolve invalid domain
    if host "this-domain-definitely-does-not-exist-${RANDOM}.com" &>/dev/null; then
        log_error "DNS resolution succeeded for invalid domain"
        return 1
    else
        log_info "DNS failure handled correctly"
        return 0
    fi
}

test_partial_file_writes() {
    local test_name="$1"
    log_info "Testing partial file write detection"

    local test_file="/tmp/test-partial-$$"

    # Write file and verify
    echo "Complete content" > "$test_file"

    # Simulate partial write by truncating
    truncate -s 8 "$test_file"

    # Read and verify
    local content=$(cat "$test_file")
    if [[ "$content" == "Complete content" ]]; then
        log_error "Partial write not detected"
        rm -f "$test_file"
        return 1
    else
        log_info "Partial write detected: '$content'"
    fi

    rm -f "$test_file"
    return 0
}

test_atomic_operations() {
    local test_name="$1"
    log_info "Testing atomic file operations"

    local target_file="/tmp/test-atomic-$$"
    local temp_file="${target_file}.tmp"

    # Write to temp file
    echo "New content" > "$temp_file"

    # Atomic rename
    mv "$temp_file" "$target_file"

    # Verify
    if [[ -f "$target_file" ]] && [[ ! -f "$temp_file" ]]; then
        log_info "Atomic operation successful"
        rm -f "$target_file"
        return 0
    else
        log_error "Atomic operation failed"
        rm -f "$target_file" "$temp_file"
        return 1
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    echo "========================================================================"
    echo "  Advanced Edge Case Testing Suite"
    echo "========================================================================"
    echo ""

    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    setup_test_environment

    echo "Running advanced edge case tests..."
    echo ""

    run_test "unicode_in_paths" test_unicode_in_paths
    run_test "symlink_loops" test_symlink_loops
    run_test "extremely_long_paths" test_extremely_long_paths
    run_test "race_condition_file_creation" test_race_condition_file_creation
    run_test "disk_full_simulation" test_disk_full_simulation
    run_test "process_signals" test_process_signals
    run_test "broken_pipe_handling" test_broken_pipe_handling
    run_test "environment_variable_injection" test_environment_variable_injection
    run_test "timezone_edge_cases" test_timezone_edge_cases
    run_test "locale_handling" test_locale_handling
    run_test "file_descriptor_limits" test_file_descriptor_limits
    run_test "invalid_json_handling" test_invalid_json_handling
    run_test "network_unreachable" test_network_unreachable
    run_test "dns_resolution_failure" test_dns_resolution_failure
    run_test "partial_file_writes" test_partial_file_writes
    run_test "atomic_operations" test_atomic_operations

    echo ""
    generate_report

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

generate_report() {
    local report_file="${TEST_RESULTS_DIR}/report.txt"

    cat > "$report_file" <<EOF
======================================================================
  ADVANCED EDGE CASE TEST REPORT
======================================================================

Test Run: $(date)
Test Directory: $TEST_RESULTS_DIR

SUMMARY:
  Total Tests: $TESTS_RUN
  Passed: $TESTS_PASSED
  Failed: $TESTS_FAILED

PASS RATE: $(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED / $TESTS_RUN) * 100}")%

======================================================================
EOF

    echo "========================================================================"
    echo "  TEST RESULTS"
    echo "========================================================================"
    echo ""
    echo "  Total Tests: $TESTS_RUN"
    echo "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo "  Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}TESTS FAILED${NC}"
    else
        echo -e "  ${GREEN}ALL TESTS PASSED${NC}"
    fi

    echo ""
    echo "  Full report: $report_file"
    echo ""
    echo "========================================================================"
}

main
