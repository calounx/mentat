#!/bin/bash
# ============================================================================
# Test Utilities Library
# ============================================================================
# Provides common testing utilities for Docker environment regression tests
# ============================================================================

set -euo pipefail

# Colors for output
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

# Test result tracking
declare -A TEST_RESULTS
declare -A TEST_TIMINGS
TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0
TEST_WARNINGS=0
TEST_START_TIME=""
PHASE_NAME=""

# Logging
LOG_FILE="${LOG_FILE:-/tmp/docker-test.log}"
VERBOSE="${VERBOSE:-false}"

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"

    if [[ "${VERBOSE}" == "true" ]] || [[ "${level}" != "DEBUG" ]]; then
        case "${level}" in
            ERROR)   echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} ${message}" ;;
            WARN)    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} ${message}" ;;
            SUCCESS) echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} ${message}" ;;
            INFO)    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} ${message}" ;;
            DEBUG)   echo -e "${COLOR_CYAN}[DEBUG]${COLOR_RESET} ${message}" ;;
            *)       echo "${message}" ;;
        esac
    fi
}

log_error() {
    log ERROR "$@"
}

log_warn() {
    log WARN "$@"
}

log_success() {
    log SUCCESS "$@"
}

log_info() {
    log INFO "$@"
}

log_debug() {
    log DEBUG "$@"
}

# ============================================================================
# Test Framework Functions
# ============================================================================

start_phase() {
    PHASE_NAME="$1"
    log_info "========================================================================"
    log_info "Starting Phase: ${PHASE_NAME}"
    log_info "========================================================================"
}

end_phase() {
    log_info "========================================================================"
    log_info "Completed Phase: ${PHASE_NAME}"
    log_info "========================================================================"
    echo ""
}

start_test() {
    local test_name="$1"
    TEST_COUNT=$((TEST_COUNT + 1))
    TEST_START_TIME=$(date +%s)
    log_info "Test ${TEST_COUNT}: ${test_name}"
}

end_test() {
    local test_name="$1"
    local status="$2"
    local end_time
    local duration

    end_time=$(date +%s)
    duration=$((end_time - TEST_START_TIME))

    TEST_RESULTS["${test_name}"]="${status}"
    TEST_TIMINGS["${test_name}"]="${duration}s"

    case "${status}" in
        PASS)
            TEST_PASSED=$((TEST_PASSED + 1))
            log_success "✓ ${test_name} (${duration}s)"
            ;;
        FAIL)
            TEST_FAILED=$((TEST_FAILED + 1))
            log_error "✗ ${test_name} (${duration}s)"
            ;;
        WARN)
            TEST_WARNINGS=$((TEST_WARNINGS + 1))
            log_warn "⚠ ${test_name} (${duration}s)"
            ;;
    esac
}

assert_true() {
    local condition="$1"
    local error_message="${2:-Assertion failed}"

    if eval "${condition}"; then
        return 0
    else
        log_error "${error_message}"
        return 1
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local error_message="${3:-Expected '${expected}' but got '${actual}'}"

    if [[ "${expected}" == "${actual}" ]]; then
        return 0
    else
        log_error "${error_message}"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local error_message="${3:-Expected to find '${needle}' in output}"

    if echo "${haystack}" | grep -q "${needle}"; then
        return 0
    else
        log_error "${error_message}"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local error_message="${3:-Did not expect to find '${needle}' in output}"

    if echo "${haystack}" | grep -q "${needle}"; then
        log_error "${error_message}"
        return 1
    else
        return 0
    fi
}

# ============================================================================
# Docker Utilities
# ============================================================================

docker_compose_file_exists() {
    local file="$1"
    [[ -f "${file}" ]]
}

docker_compose_validate() {
    local file="$1"
    docker compose -f "${file}" config > /dev/null 2>&1
}

docker_compose_up() {
    local file="$1"
    local timeout="${2:-300}"

    log_info "Starting containers from ${file}"
    docker compose -f "${file}" up -d

    # Wait for containers to be running
    local elapsed=0
    local interval=5

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local status
        status=$(docker compose -f "${file}" ps --format json 2>/dev/null | jq -r '.[].State' 2>/dev/null || echo "error")

        if [[ "${status}" == "error" ]]; then
            sleep ${interval}
            elapsed=$((elapsed + interval))
            continue
        fi

        # Check if all containers are running or healthy
        local all_running=true
        while IFS= read -r state; do
            if [[ "${state}" != "running" ]]; then
                all_running=false
                break
            fi
        done < <(docker compose -f "${file}" ps --format json | jq -r '.[].State')

        if ${all_running}; then
            log_success "All containers are running"
            return 0
        fi

        sleep ${interval}
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout waiting for containers to start"
    return 1
}

docker_compose_down() {
    local file="$1"
    log_info "Stopping containers from ${file}"
    docker compose -f "${file}" down --remove-orphans
}

docker_compose_cleanup() {
    local file="$1"
    log_info "Cleaning up containers, networks, and volumes from ${file}"
    docker compose -f "${file}" down -v --remove-orphans
}

container_is_running() {
    local container="$1"
    docker ps --filter "name=${container}" --format "{{.Names}}" | grep -q "^${container}$"
}

container_is_healthy() {
    local container="$1"
    local health
    health=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "none")

    if [[ "${health}" == "healthy" ]]; then
        return 0
    elif [[ "${health}" == "none" ]]; then
        # No health check defined, check if running
        container_is_running "${container}"
    else
        return 1
    fi
}

wait_for_healthy() {
    local container="$1"
    local timeout="${2:-120}"
    local elapsed=0
    local interval=5

    log_info "Waiting for ${container} to be healthy..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if container_is_healthy "${container}"; then
            log_success "${container} is healthy"
            return 0
        fi

        sleep ${interval}
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout waiting for ${container} to be healthy"
    return 1
}

exec_in_container() {
    local container="$1"
    shift
    docker exec "${container}" "$@"
}

get_container_logs() {
    local container="$1"
    local lines="${2:-100}"
    docker logs --tail "${lines}" "${container}"
}

# ============================================================================
# Network Utilities
# ============================================================================

check_port_listening() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    timeout "${timeout}" bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null
}

check_http_endpoint() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-10}"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${timeout}" "${url}" 2>/dev/null || echo "000")

    [[ "${status}" == "${expected_status}" ]]
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local elapsed=0
    local interval=2

    log_info "Waiting for ${host}:${port} to be available..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if check_port_listening "${host}" "${port}"; then
            log_success "${host}:${port} is available"
            return 0
        fi

        sleep ${interval}
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout waiting for ${host}:${port}"
    return 1
}

wait_for_http() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-60}"
    local elapsed=0
    local interval=2

    log_info "Waiting for ${url} to respond with ${expected_status}..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if check_http_endpoint "${url}" "${expected_status}"; then
            log_success "${url} is responding"
            return 0
        fi

        sleep ${interval}
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout waiting for ${url}"
    return 1
}

# ============================================================================
# Report Generation
# ============================================================================

generate_json_report() {
    local output_file="$1"
    local test_suite="$2"
    local start_time="$3"
    local end_time="$4"

    local duration=$((end_time - start_time))

    cat > "${output_file}" <<EOF
{
  "test_suite": "${test_suite}",
  "timestamp": "$(date -Iseconds)",
  "duration": ${duration},
  "summary": {
    "total": ${TEST_COUNT},
    "passed": ${TEST_PASSED},
    "failed": ${TEST_FAILED},
    "warnings": ${TEST_WARNINGS}
  },
  "results": {
EOF

    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ "${first}" == "true" ]]; then
            first=false
        else
            echo "," >> "${output_file}"
        fi

        cat >> "${output_file}" <<EOF
    "${test_name}": {
      "status": "${TEST_RESULTS[${test_name}]}",
      "duration": "${TEST_TIMINGS[${test_name}]}"
    }
EOF
    done

    cat >> "${output_file}" <<EOF

  }
}
EOF

    log_success "JSON report generated: ${output_file}"
}

generate_markdown_report() {
    local output_file="$1"
    local test_suite="$2"
    local start_time="$3"
    local end_time="$4"

    local duration=$((end_time - start_time))

    cat > "${output_file}" <<EOF
# Docker Environment Regression Test Report

**Test Suite:** ${test_suite}
**Date:** $(date -Iseconds)
**Duration:** ${duration}s

## Summary

| Metric | Count |
|--------|-------|
| Total Tests | ${TEST_COUNT} |
| Passed | ${TEST_PASSED} |
| Failed | ${TEST_FAILED} |
| Warnings | ${TEST_WARNINGS} |

## Test Results

| Test Name | Status | Duration |
|-----------|--------|----------|
EOF

    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[${test_name}]}"
        local icon

        case "${status}" in
            PASS) icon="✓" ;;
            FAIL) icon="✗" ;;
            WARN) icon="⚠" ;;
        esac

        echo "| ${test_name} | ${icon} ${status} | ${TEST_TIMINGS[${test_name}]} |" >> "${output_file}"
    done

    cat >> "${output_file}" <<EOF

## Exit Code

EOF

    if [[ ${TEST_FAILED} -gt 0 ]]; then
        echo "**2** - Failures detected" >> "${output_file}"
    elif [[ ${TEST_WARNINGS} -gt 0 ]]; then
        echo "**1** - Warnings detected" >> "${output_file}"
    else
        echo "**0** - All tests passed" >> "${output_file}"
    fi

    log_success "Markdown report generated: ${output_file}"
}

print_summary() {
    echo ""
    log_info "========================================================================"
    log_info "Test Summary"
    log_info "========================================================================"
    log_info "Total Tests:  ${TEST_COUNT}"
    log_success "Passed:       ${TEST_PASSED}"
    log_error "Failed:       ${TEST_FAILED}"
    log_warn "Warnings:     ${TEST_WARNINGS}"
    log_info "========================================================================"
    echo ""
}

get_exit_code() {
    if [[ ${TEST_FAILED} -gt 0 ]]; then
        return 2
    elif [[ ${TEST_WARNINGS} -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}
