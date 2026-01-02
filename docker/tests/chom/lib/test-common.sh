#!/bin/bash
# ==============================================================================
# CHOM Test Common Library
# ==============================================================================
# Shared functions for all CHOM regression tests
#
# Usage: source lib/test-common.sh
# ==============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Container and connection settings
CONTAINER_NAME="${CONTAINER_NAME:-landsraad_tst}"
WEB_HOST="${WEB_HOST:-localhost}"
WEB_PORT="${WEB_PORT:-8000}"
MYSQL_PORT="${MYSQL_PORT:-3316}"
REDIS_PORT="${REDIS_PORT:-6389}"

# Database credentials (from docker-compose.vps.yml)
DB_DATABASE="${DB_DATABASE:-chom}"
DB_USERNAME="${DB_USERNAME:-chom}"
DB_PASSWORD="${DB_PASSWORD:-secret}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"

# Paths
APP_PATH="/var/www/vpsmanager"
CHOM_PATH="/opt/chom"

# ==============================================================================
# Output Functions
# ==============================================================================

print_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  ${title}${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

print_test() {
    local test_name="$1"
    echo -ne "  Testing: ${test_name}... "
}

print_pass() {
    local message="${1:-OK}"
    echo -e "${GREEN}PASS${NC} ${message}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    local message="${1:-FAILED}"
    echo -e "${RED}FAIL${NC} ${message}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_skip() {
    local message="${1:-Skipped}"
    echo -e "${YELLOW}SKIP${NC} ${message}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

print_info() {
    local message="$1"
    echo -e "${CYAN}  INFO:${NC} ${message}"
}

print_summary() {
    local suite_name="$1"
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    echo ""
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE}  Summary: ${suite_name}${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "  Total Tests: ${total}"
    echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}"
    echo -e "  ${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
    echo ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}  All tests passed!${NC}"
    else
        echo -e "${RED}  Some tests failed!${NC}"
    fi
    echo ""
}

# ==============================================================================
# Container Functions
# ==============================================================================

# Check if container is running
container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

# Execute command in container
container_exec() {
    docker exec "${CONTAINER_NAME}" "$@"
}

# Execute command in container with bash
container_bash() {
    docker exec "${CONTAINER_NAME}" bash -c "$1"
}

# Check if a service is running in container
service_running() {
    local service="$1"
    container_bash "systemctl is-active ${service}" 2>/dev/null | grep -q "^active$"
}

# Get service status
service_status() {
    local service="$1"
    container_bash "systemctl is-active ${service}" 2>/dev/null
}

# ==============================================================================
# HTTP Functions
# ==============================================================================

# Make HTTP request (from host)
http_get() {
    local path="$1"
    local expected_code="${2:-200}"
    local url="http://${WEB_HOST}:${WEB_PORT}${path}"

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null)

    if [[ "${response}" == "${expected_code}" ]]; then
        return 0
    else
        return 1
    fi
}

# Make HTTP request and get body
http_get_body() {
    local path="$1"
    local url="http://${WEB_HOST}:${WEB_PORT}${path}"
    curl -s "${url}" 2>/dev/null
}

# Make HTTP request and get headers
http_get_headers() {
    local path="$1"
    local url="http://${WEB_HOST}:${WEB_PORT}${path}"
    curl -sI "${url}" 2>/dev/null
}

# Check HTTP response code
check_http_code() {
    local path="$1"
    local url="http://${WEB_HOST}:${WEB_PORT}${path}"
    curl -s -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null
}

# Make HTTP POST request
http_post() {
    local path="$1"
    local data="$2"
    local content_type="${3:-application/json}"
    local url="http://${WEB_HOST}:${WEB_PORT}${path}"

    curl -s -X POST -H "Content-Type: ${content_type}" -d "${data}" "${url}" 2>/dev/null
}

# ==============================================================================
# Database Functions
# ==============================================================================

# Execute MySQL query from host
mysql_query() {
    local query="$1"
    local db="${2:-${DB_DATABASE}}"

    mysql -h "${WEB_HOST}" -P "${MYSQL_PORT}" -u "${DB_USERNAME}" -p"${DB_PASSWORD}" \
        "${db}" -N -e "${query}" 2>/dev/null
}

# Execute MySQL query as root
mysql_root_query() {
    local query="$1"

    mysql -h "${WEB_HOST}" -P "${MYSQL_PORT}" -u root -p"${MYSQL_ROOT_PASSWORD}" \
        -N -e "${query}" 2>/dev/null
}

# Check if database exists
database_exists() {
    local db_name="$1"
    local result
    result=$(mysql_root_query "SHOW DATABASES LIKE '${db_name}';" 2>/dev/null)
    [[ -n "${result}" ]]
}

# Check if table exists
table_exists() {
    local table_name="$1"
    local db="${2:-${DB_DATABASE}}"
    local result
    result=$(mysql_query "SHOW TABLES LIKE '${table_name}';" "${db}" 2>/dev/null)
    [[ -n "${result}" ]]
}

# ==============================================================================
# Redis Functions
# ==============================================================================

# Execute Redis command from host
redis_cmd() {
    local cmd="$1"
    redis-cli -h "${WEB_HOST}" -p "${REDIS_PORT}" ${cmd} 2>/dev/null
}

# Check Redis connection
redis_ping() {
    local result
    result=$(redis-cli -h "${WEB_HOST}" -p "${REDIS_PORT}" ping 2>/dev/null)
    [[ "${result}" == "PONG" ]]
}

# ==============================================================================
# JSON Functions
# ==============================================================================

# Check if string is valid JSON
is_valid_json() {
    local json="$1"
    echo "${json}" | jq empty 2>/dev/null
}

# Get JSON field value
json_get() {
    local json="$1"
    local field="$2"
    echo "${json}" | jq -r "${field}" 2>/dev/null
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================

# Check all prerequisites before running tests
check_prerequisites() {
    local missing=0

    # Check required commands
    for cmd in docker curl jq; do
        if ! command -v "${cmd}" &>/dev/null; then
            echo -e "${RED}ERROR: Required command '${cmd}' not found${NC}"
            missing=$((missing + 1))
        fi
    done

    # Check container is running
    if ! container_running; then
        echo -e "${RED}ERROR: Container '${CONTAINER_NAME}' is not running${NC}"
        echo "  Start it with: docker compose -f docker-compose.vps.yml up -d"
        missing=$((missing + 1))
    fi

    if [[ ${missing} -gt 0 ]]; then
        exit 1
    fi
}

# ==============================================================================
# Test Execution Helpers
# ==============================================================================

# Run a test and capture result
run_test() {
    local test_name="$1"
    local test_cmd="$2"

    print_test "${test_name}"

    if eval "${test_cmd}"; then
        print_pass
        return 0
    else
        print_fail
        return 1
    fi
}

# Run test with expected output
run_test_expect() {
    local test_name="$1"
    local test_cmd="$2"
    local expected="$3"

    print_test "${test_name}"

    local actual
    actual=$(eval "${test_cmd}")

    if [[ "${actual}" == "${expected}" ]]; then
        print_pass
        return 0
    else
        print_fail "(expected: ${expected}, got: ${actual})"
        return 1
    fi
}

# Run test with expected output containing substring
run_test_contains() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_substring="$3"

    print_test "${test_name}"

    local actual
    actual=$(eval "${test_cmd}")

    if [[ "${actual}" == *"${expected_substring}"* ]]; then
        print_pass
        return 0
    else
        print_fail "(expected to contain: ${expected_substring})"
        return 1
    fi
}

# Skip test with reason
skip_test() {
    local test_name="$1"
    local reason="$2"

    print_test "${test_name}"
    print_skip "${reason}"
}

# Get exit code (0 if all passed, 1 if any failed)
get_exit_code() {
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        return 1
    fi
    return 0
}
