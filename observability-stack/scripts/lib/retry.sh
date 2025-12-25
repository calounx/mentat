#!/bin/bash
#===============================================================================
# Retry Library
# Retry logic with exponential backoff, timeout handling, and circuit breaker pattern
#===============================================================================

# Guard against multiple sourcing
[[ -n "${RETRY_SH_LOADED:-}" ]] && return 0
RETRY_SH_LOADED=1

# Source dependencies
_RETRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    source "$_RETRY_DIR/common.sh"
fi
if [[ -z "${ERRORS_SH_LOADED:-}" ]]; then
    source "$_RETRY_DIR/errors.sh"
fi

#===============================================================================
# RETRY CONFIGURATION
#===============================================================================

# Default retry settings
readonly DEFAULT_MAX_ATTEMPTS=3
readonly DEFAULT_INITIAL_DELAY=1
readonly DEFAULT_MAX_DELAY=60
readonly DEFAULT_BACKOFF_MULTIPLIER=2
readonly DEFAULT_TIMEOUT=300  # 5 minutes

# Retry state tracking
declare -gA RETRY_STATE=()

#===============================================================================
# BASIC RETRY LOGIC
#===============================================================================

# Retry a command with exponential backoff
# Usage: retry_with_backoff "description" command [args...]
# Environment variables:
#   RETRY_MAX_ATTEMPTS - maximum number of attempts (default: 3)
#   RETRY_INITIAL_DELAY - initial delay in seconds (default: 1)
#   RETRY_MAX_DELAY - maximum delay in seconds (default: 60)
#   RETRY_BACKOFF_MULTIPLIER - backoff multiplier (default: 2)
retry_with_backoff() {
    local description="$1"
    shift
    local max_attempts="${RETRY_MAX_ATTEMPTS:-$DEFAULT_MAX_ATTEMPTS}"
    local delay="${RETRY_INITIAL_DELAY:-$DEFAULT_INITIAL_DELAY}"
    local max_delay="${RETRY_MAX_DELAY:-$DEFAULT_MAX_DELAY}"
    local multiplier="${RETRY_BACKOFF_MULTIPLIER:-$DEFAULT_BACKOFF_MULTIPLIER}"

    local attempt=1
    local last_error=""

    error_push_context "Retry: $description"

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $description"

        # Try to execute the command
        if "$@" 2>&1; then
            log_debug "Success on attempt $attempt: $description"
            error_pop_context
            return 0
        fi

        last_error=$?

        # If this was the last attempt, fail
        if [[ $attempt -eq $max_attempts ]]; then
            error_report "Failed after $max_attempts attempts: $description" "$E_RETRY_EXHAUSTED"
            error_pop_context
            return "$last_error"
        fi

        # Calculate next delay with exponential backoff
        log_warn "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"

        delay=$((delay * multiplier))
        if [[ $delay -gt $max_delay ]]; then
            delay=$max_delay
        fi

        ((attempt++))
    done

    error_pop_context
    return "$last_error"
}

# Simple retry without backoff (fixed delay)
# Usage: retry_fixed "description" delay max_attempts command [args...]
retry_fixed() {
    local description="$1"
    local delay="$2"
    local max_attempts="$3"
    shift 3

    local attempt=1
    local last_error=""

    error_push_context "Retry: $description"

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $description"

        if "$@" 2>&1; then
            log_debug "Success on attempt $attempt: $description"
            error_pop_context
            return 0
        fi

        last_error=$?

        if [[ $attempt -eq $max_attempts ]]; then
            error_report "Failed after $max_attempts attempts: $description" "$E_RETRY_EXHAUSTED"
            error_pop_context
            return "$last_error"
        fi

        log_warn "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done

    error_pop_context
    return "$last_error"
}

# Retry until success or timeout
# Usage: retry_until_timeout "description" timeout_seconds command [args...]
retry_until_timeout() {
    local description="$1"
    local timeout="$2"
    shift 2

    local start_time
    start_time=$(date +%s)
    local attempt=1

    error_push_context "Retry until timeout: $description"

    while true; do
        local elapsed=$(($(date +%s) - start_time))

        if [[ $elapsed -ge $timeout ]]; then
            error_report "Timeout after ${timeout}s: $description" "$E_TIMEOUT"
            error_pop_context
            return 1
        fi

        log_debug "Attempt $attempt (${elapsed}s elapsed): $description"

        if "$@" 2>&1; then
            log_debug "Success after ${elapsed}s: $description"
            error_pop_context
            return 0
        fi

        # Wait 1 second before next attempt
        sleep 1
        ((attempt++))
    done

    error_pop_context
}

#===============================================================================
# RETRY WITH PROGRESS CALLBACK
#===============================================================================

# Retry with custom callback on each attempt
# Usage: retry_with_callback "description" callback_func max_attempts command [args...]
# Callback signature: callback_func attempt max_attempts
retry_with_callback() {
    local description="$1"
    local callback="$2"
    local max_attempts="$3"
    shift 3

    local attempt=1
    local last_error=""

    error_push_context "Retry with callback: $description"

    while [[ $attempt -le $max_attempts ]]; do
        # Call progress callback
        if declare -f "$callback" &>/dev/null; then
            "$callback" "$attempt" "$max_attempts"
        fi

        if "$@" 2>&1; then
            error_pop_context
            return 0
        fi

        last_error=$?

        if [[ $attempt -eq $max_attempts ]]; then
            error_report "Failed after $max_attempts attempts: $description" "$E_RETRY_EXHAUSTED"
            error_pop_context
            return "$last_error"
        fi

        ((attempt++))
        sleep 1
    done

    error_pop_context
    return "$last_error"
}

#===============================================================================
# NETWORK OPERATION WRAPPERS
#===============================================================================

# Retry network download with exponential backoff
# Usage: retry_download "url" "output_file" [max_attempts]
retry_download() {
    local url="$1"
    local output_file="$2"
    local max_attempts="${3:-5}"

    RETRY_MAX_ATTEMPTS="$max_attempts" \
    RETRY_INITIAL_DELAY=2 \
    RETRY_MAX_DELAY=30 \
        retry_with_backoff "Download $url" \
        curl -fsSL -o "$output_file" "$url"
}

# Retry HTTP request with backoff
# Usage: retry_http_get "url" [max_attempts]
retry_http_get() {
    local url="$1"
    local max_attempts="${2:-3}"

    RETRY_MAX_ATTEMPTS="$max_attempts" \
    RETRY_INITIAL_DELAY=1 \
    RETRY_MAX_DELAY=10 \
        retry_with_backoff "HTTP GET $url" \
        curl -fsSL "$url"
}

# Retry HTTP POST with backoff
# Usage: retry_http_post "url" "data" [max_attempts]
retry_http_post() {
    local url="$1"
    local data="$2"
    local max_attempts="${3:-3}"

    RETRY_MAX_ATTEMPTS="$max_attempts" \
    RETRY_INITIAL_DELAY=1 \
    RETRY_MAX_DELAY=10 \
        retry_with_backoff "HTTP POST $url" \
        curl -fsSL -X POST -d "$data" "$url"
}

# Wait for HTTP endpoint to become available
# Usage: retry_wait_for_http "url" [timeout_seconds]
retry_wait_for_http() {
    local url="$1"
    local timeout="${2:-60}"

    retry_until_timeout "Wait for $url" "$timeout" \
        curl -fsSL -o /dev/null "$url"
}

# Wait for TCP port to become available
# Usage: retry_wait_for_port "host" "port" [timeout_seconds]
retry_wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"

    retry_until_timeout "Wait for $host:$port" "$timeout" \
        bash -c "timeout 2 bash -c 'echo >/dev/tcp/$host/$port' 2>/dev/null"
}

#===============================================================================
# CIRCUIT BREAKER PATTERN
#===============================================================================

# Circuit breaker states
readonly CB_STATE_CLOSED="closed"      # Normal operation
readonly CB_STATE_OPEN="open"          # Circuit broken, rejecting requests
readonly CB_STATE_HALF_OPEN="half_open"  # Testing if service recovered

# Circuit breaker configuration per identifier
declare -gA CB_STATE=()          # Current state
declare -gA CB_FAILURES=()       # Failure count
declare -gA CB_LAST_FAILURE=()   # Timestamp of last failure
declare -gA CB_OPEN_TIME=()      # Timestamp when circuit opened

# Circuit breaker thresholds (can be overridden)
readonly CB_FAILURE_THRESHOLD="${CB_FAILURE_THRESHOLD:-5}"
readonly CB_TIMEOUT="${CB_TIMEOUT:-60}"  # Seconds before trying half-open
readonly CB_SUCCESS_THRESHOLD="${CB_SUCCESS_THRESHOLD:-2}"  # Successes needed to close

# Initialize circuit breaker for an identifier
# Usage: circuit_breaker_init "identifier"
circuit_breaker_init() {
    local id="$1"

    CB_STATE["$id"]="$CB_STATE_CLOSED"
    CB_FAILURES["$id"]=0
    CB_LAST_FAILURE["$id"]=0
    CB_OPEN_TIME["$id"]=0

    log_debug "Circuit breaker initialized: $id"
}

# Get circuit breaker state
# Usage: circuit_breaker_get_state "identifier"
circuit_breaker_get_state() {
    local id="$1"

    # Auto-initialize if not exists
    if [[ -z "${CB_STATE[$id]:-}" ]]; then
        circuit_breaker_init "$id"
    fi

    echo "${CB_STATE[$id]}"
}

# Record a success for circuit breaker
# Usage: circuit_breaker_success "identifier"
circuit_breaker_success() {
    local id="$1"
    local state
    state=$(circuit_breaker_get_state "$id")

    case "$state" in
        "$CB_STATE_CLOSED")
            # Reset failure count
            CB_FAILURES["$id"]=0
            ;;
        "$CB_STATE_HALF_OPEN")
            # Check if we've had enough successes to close
            local successes=$((CB_SUCCESS_THRESHOLD - CB_FAILURES["$id"]))
            if [[ $successes -ge $CB_SUCCESS_THRESHOLD ]]; then
                log_info "Circuit breaker closing: $id"
                CB_STATE["$id"]="$CB_STATE_CLOSED"
                CB_FAILURES["$id"]=0
            fi
            ;;
    esac

    log_debug "Circuit breaker success: $id (state: ${CB_STATE[$id]})"
}

# Record a failure for circuit breaker
# Usage: circuit_breaker_failure "identifier"
circuit_breaker_failure() {
    local id="$1"
    local state
    state=$(circuit_breaker_get_state "$id")

    local now
    now=$(date +%s)
    CB_LAST_FAILURE["$id"]="$now"

    case "$state" in
        "$CB_STATE_CLOSED")
            CB_FAILURES["$id"]=$((CB_FAILURES["$id"] + 1))

            if [[ ${CB_FAILURES["$id"]} -ge $CB_FAILURE_THRESHOLD ]]; then
                log_warn "Circuit breaker opening: $id (failures: ${CB_FAILURES[$id]})"
                CB_STATE["$id"]="$CB_STATE_OPEN"
                CB_OPEN_TIME["$id"]="$now"
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            # Failed during test, reopen circuit
            log_warn "Circuit breaker reopening: $id"
            CB_STATE["$id"]="$CB_STATE_OPEN"
            CB_OPEN_TIME["$id"]="$now"
            CB_FAILURES["$id"]=$CB_FAILURE_THRESHOLD
            ;;
    esac

    log_debug "Circuit breaker failure: $id (state: ${CB_STATE[$id]}, failures: ${CB_FAILURES[$id]})"
}

# Check if circuit breaker allows execution
# Usage: circuit_breaker_allow "identifier"
circuit_breaker_allow() {
    local id="$1"
    local state
    state=$(circuit_breaker_get_state "$id")

    case "$state" in
        "$CB_STATE_CLOSED")
            return 0
            ;;
        "$CB_STATE_HALF_OPEN")
            return 0
            ;;
        "$CB_STATE_OPEN")
            # Check if timeout has elapsed
            local now
            now=$(date +%s)
            local elapsed=$((now - CB_OPEN_TIME["$id"]))

            if [[ $elapsed -ge $CB_TIMEOUT ]]; then
                log_info "Circuit breaker trying half-open: $id"
                CB_STATE["$id"]="$CB_STATE_HALF_OPEN"
                CB_FAILURES["$id"]=0
                return 0
            fi

            log_debug "Circuit breaker rejecting request: $id (open for ${elapsed}s)"
            return 1
            ;;
    esac
}

# Execute command with circuit breaker protection
# Usage: circuit_breaker_exec "identifier" "description" command [args...]
circuit_breaker_exec() {
    local id="$1"
    local description="$2"
    shift 2

    # Check if circuit allows execution
    if ! circuit_breaker_allow "$id"; then
        error_report "Circuit breaker open for: $description" "$E_RESOURCE_UNAVAILABLE"
        return 1
    fi

    # Execute command
    if "$@"; then
        circuit_breaker_success "$id"
        return 0
    else
        local code=$?
        circuit_breaker_failure "$id"
        error_report "Circuit breaker failure: $description" "$code"
        return "$code"
    fi
}

# Reset circuit breaker
# Usage: circuit_breaker_reset "identifier"
circuit_breaker_reset() {
    local id="$1"

    CB_STATE["$id"]="$CB_STATE_CLOSED"
    CB_FAILURES["$id"]=0
    CB_LAST_FAILURE["$id"]=0
    CB_OPEN_TIME["$id"]=0

    log_info "Circuit breaker reset: $id"
}

# Get circuit breaker status
# Usage: circuit_breaker_status "identifier"
circuit_breaker_status() {
    local id="$1"

    if [[ -z "${CB_STATE[$id]:-}" ]]; then
        echo "Circuit breaker '$id': not initialized"
        return 1
    fi

    local state="${CB_STATE[$id]}"
    local failures="${CB_FAILURES[$id]}"
    local last_failure="${CB_LAST_FAILURE[$id]}"

    echo "Circuit breaker '$id':"
    echo "  State: $state"
    echo "  Failures: $failures / $CB_FAILURE_THRESHOLD"

    if [[ $last_failure -gt 0 ]]; then
        local elapsed=$(($(date +%s) - last_failure))
        echo "  Last failure: ${elapsed}s ago"
    fi

    if [[ "$state" == "$CB_STATE_OPEN" ]]; then
        local open_elapsed=$(($(date +%s) - CB_OPEN_TIME["$id"]))
        local remaining=$((CB_TIMEOUT - open_elapsed))
        echo "  Open for: ${open_elapsed}s (${remaining}s until half-open)"
    fi
}

#===============================================================================
# TIMEOUT HANDLING
#===============================================================================

# Execute command with timeout
# Usage: with_timeout timeout_seconds "description" command [args...]
with_timeout() {
    local timeout_seconds="$1"
    local description="$2"
    shift 2

    error_push_context "Timeout: $description"

    if timeout "$timeout_seconds" "$@"; then
        error_pop_context
        return 0
    else
        local code=$?
        if [[ $code -eq 124 ]]; then
            error_report "Operation timed out after ${timeout_seconds}s: $description" "$E_TIMEOUT"
        else
            error_report "Operation failed: $description" "$code"
        fi
        error_pop_context
        return "$code"
    fi
}

#===============================================================================
# USAGE EXAMPLES
#===============================================================================

# Example 1: Simple retry with exponential backoff
# retry_with_backoff "Connect to database" mysql -h localhost -e "SELECT 1"

# Example 2: Download with retry
# retry_download "https://example.com/file.tar.gz" "/tmp/file.tar.gz" 5

# Example 3: Wait for service to be ready
# retry_wait_for_port "localhost" "9090" 60

# Example 4: Circuit breaker for external service
# circuit_breaker_exec "external_api" "Call API" curl -f "https://api.example.com/data"

# Example 5: Operation with timeout
# with_timeout 30 "Long operation" ./long-running-script.sh

# Example 6: Custom retry with callback
# progress_callback() {
#     echo "Attempt $1 of $2..."
# }
# retry_with_callback "Custom operation" progress_callback 5 my_command

# Example 7: Check circuit breaker status
# circuit_breaker_status "external_api"

# Example 8: Reset circuit breaker manually
# circuit_breaker_reset "external_api"
