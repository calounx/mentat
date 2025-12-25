#!/bin/bash
#===============================================================================
# Error Handling Library
# Comprehensive error management with stack traces, reporting, and recovery
#===============================================================================

# Guard against multiple sourcing
[[ -n "${ERRORS_SH_LOADED:-}" ]] && return 0
ERRORS_SH_LOADED=1

# Source common library for logging
_ERRORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    source "$_ERRORS_DIR/common.sh"
fi

#===============================================================================
# ERROR CODES EXTENSION
# Extended error codes beyond common.sh
#===============================================================================

# Additional error codes
readonly E_RETRY_EXHAUSTED=8
readonly E_TIMEOUT=9
readonly E_DEPENDENCY_MISSING=10
readonly E_ROLLBACK_FAILED=11
readonly E_RESOURCE_UNAVAILABLE=12
readonly E_INVALID_STATE=13
readonly E_ALREADY_EXISTS=14
readonly E_NOT_FOUND=15
readonly E_BACKUP_FAILED=16
readonly E_RESTORE_FAILED=17
readonly E_TRANSACTION_FAILED=18

# Error code descriptions
declare -gA ERROR_DESCRIPTIONS=(
    [0]="Success"
    [1]="General error"
    [2]="Module not found"
    [3]="Validation failed"
    [4]="Installation failed"
    [5]="Permission denied"
    [6]="Configuration error"
    [7]="Network error"
    [8]="Retry exhausted"
    [9]="Timeout"
    [10]="Dependency missing"
    [11]="Rollback failed"
    [12]="Resource unavailable"
    [13]="Invalid state"
    [14]="Already exists"
    [15]="Not found"
    [16]="Backup failed"
    [17]="Restore failed"
    [18]="Transaction failed"
)

#===============================================================================
# ERROR CONTEXT AND STACK TRACE
#===============================================================================

# Global error context stack
declare -ga ERROR_STACK=()
declare -g ERROR_CONTEXT=""
declare -g LAST_ERROR_CODE=0
declare -g LAST_ERROR_MESSAGE=""
declare -g LAST_ERROR_FILE=""
declare -g LAST_ERROR_LINE=""
declare -g LAST_ERROR_FUNCTION=""

# Error aggregation (for batch operations)
declare -ga ERROR_AGGREGATE=()
declare -g ERROR_AGGREGATE_MODE="${ERROR_AGGREGATE_MODE:-false}"

# Error recovery hooks
declare -gA ERROR_RECOVERY_HOOKS=()

# Error log file
readonly ERROR_LOG="${ERROR_LOG:-/var/log/observability-errors.log}"

#===============================================================================
# ERROR CONTEXT MANAGEMENT
#===============================================================================

# Push an error context onto the stack
# Usage: error_push_context "operation description"
error_push_context() {
    local context="$1"
    ERROR_STACK+=("$context")
    ERROR_CONTEXT="$context"
    log_debug "Error context: $context"
}

# Pop error context from the stack
# Usage: error_pop_context
error_pop_context() {
    if [[ ${#ERROR_STACK[@]} -gt 0 ]]; then
        unset 'ERROR_STACK[${#ERROR_STACK[@]}-1]'
        if [[ ${#ERROR_STACK[@]} -gt 0 ]]; then
            ERROR_CONTEXT="${ERROR_STACK[${#ERROR_STACK[@]}-1]}"
        else
            ERROR_CONTEXT=""
        fi
    fi
}

# Get current error context path
# Usage: error_get_context
error_get_context() {
    if [[ ${#ERROR_STACK[@]} -eq 0 ]]; then
        echo "root"
    else
        local IFS=" > "
        echo "${ERROR_STACK[*]}"
    fi
}

#===============================================================================
# ERROR CAPTURE AND STACK TRACE
#===============================================================================

# Capture error with stack trace
# Usage: error_capture [exit_code] [message] [file] [line]
error_capture() {
    local code="${1:-$?}"
    local message="${2:-Unknown error}"
    local file="${3:-${BASH_SOURCE[2]:-unknown}}"
    local line="${4:-${BASH_LINENO[1]:-0}}"
    local func="${FUNCNAME[2]:-main}"

    LAST_ERROR_CODE="$code"
    LAST_ERROR_MESSAGE="$message"
    LAST_ERROR_FILE="$file"
    LAST_ERROR_LINE="$line"
    LAST_ERROR_FUNCTION="$func"

    # Log to error file
    if [[ -n "$ERROR_LOG" ]]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local context
        context=$(error_get_context)

        cat >> "$ERROR_LOG" << EOF
[$timestamp] ERROR CODE: $code
Context: $context
Message: $message
Location: $file:$line in $func()
Stack trace:
$(error_get_stack_trace)
---
EOF
    fi

    return "$code"
}

# Get formatted stack trace
# Usage: error_get_stack_trace
error_get_stack_trace() {
    local i=1
    local frame_count=${#FUNCNAME[@]}

    for ((i=1; i<frame_count; i++)); do
        local func="${FUNCNAME[$i]}"
        local file="${BASH_SOURCE[$i]}"
        local line="${BASH_LINENO[$((i-1))]}"

        # Skip internal error handling functions
        [[ "$func" =~ ^error_ ]] && continue

        echo "  $((i-1)). $func() at $file:$line"
    done
}

# Print formatted error with stack trace
# Usage: error_print
error_print() {
    local code="${LAST_ERROR_CODE:-1}"
    local message="${LAST_ERROR_MESSAGE:-Unknown error}"
    local context
    context=$(error_get_context)

    echo -e "${RED}[ERROR]${NC} $message (code: $code)" >&2

    if [[ -n "$context" ]] && [[ "$context" != "root" ]]; then
        echo -e "${YELLOW}Context:${NC} $context" >&2
    fi

    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${YELLOW}Location:${NC} ${LAST_ERROR_FILE}:${LAST_ERROR_LINE} in ${LAST_ERROR_FUNCTION}()" >&2
        echo -e "${YELLOW}Stack trace:${NC}" >&2
        error_get_stack_trace >&2
    fi
}

#===============================================================================
# ERROR REPORTING
#===============================================================================

# Get error description from code
# Usage: error_description [code]
error_description() {
    local code="${1:-$LAST_ERROR_CODE}"
    echo "${ERROR_DESCRIPTIONS[$code]:-Unknown error ($code)}"
}

# Report error and optionally exit
# Usage: error_report "message" [exit_code] [should_exit]
error_report() {
    local message="$1"
    local code="${2:-1}"
    local should_exit="${3:-false}"

    error_capture "$code" "$message"

    # Aggregate mode: collect errors instead of reporting immediately
    if [[ "$ERROR_AGGREGATE_MODE" == "true" ]]; then
        ERROR_AGGREGATE+=("[$code] $message")
        return "$code"
    fi

    error_print

    # Try recovery hook if registered
    if error_try_recovery "$code"; then
        log_success "Error recovered successfully"
        return 0
    fi

    if [[ "$should_exit" == "true" ]]; then
        exit "$code"
    fi

    return "$code"
}

# Report fatal error and exit
# Usage: error_fatal "message" [exit_code]
error_fatal() {
    local message="$1"
    local code="${2:-1}"

    error_report "$message" "$code" true
}

# Report error only if DEBUG mode is enabled
# Usage: error_debug "message" [code]
error_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        error_report "$@"
    fi
}

#===============================================================================
# ERROR AGGREGATION
#===============================================================================

# Enable error aggregation mode
# Usage: error_aggregate_start
error_aggregate_start() {
    ERROR_AGGREGATE_MODE=true
    ERROR_AGGREGATE=()
    log_debug "Error aggregation enabled"
}

# Disable error aggregation and report all
# Usage: error_aggregate_finish
error_aggregate_finish() {
    ERROR_AGGREGATE_MODE=false

    if [[ ${#ERROR_AGGREGATE[@]} -gt 0 ]]; then
        log_error "Aggregated errors (${#ERROR_AGGREGATE[@]}):"
        for err in "${ERROR_AGGREGATE[@]}"; do
            echo "  - $err" >&2
        done
        ERROR_AGGREGATE=()
        return 1
    fi

    return 0
}

# Get count of aggregated errors
# Usage: error_aggregate_count
error_aggregate_count() {
    echo "${#ERROR_AGGREGATE[@]}"
}

# Check if there are aggregated errors
# Usage: error_aggregate_has_errors
error_aggregate_has_errors() {
    [[ ${#ERROR_AGGREGATE[@]} -gt 0 ]]
}

#===============================================================================
# ERROR RECOVERY
#===============================================================================

# Register an error recovery hook
# Usage: error_register_recovery [error_code] "recovery_function"
error_register_recovery() {
    local code="${1:-*}"
    local recovery_func="$2"

    ERROR_RECOVERY_HOOKS["$code"]="$recovery_func"
    log_debug "Registered recovery hook for error $code: $recovery_func"
}

# Unregister an error recovery hook
# Usage: error_unregister_recovery [error_code]
error_unregister_recovery() {
    local code="${1:-*}"
    unset 'ERROR_RECOVERY_HOOKS[$code]'
}

# Try to recover from error using registered hooks
# Usage: error_try_recovery [error_code]
error_try_recovery() {
    local code="${1:-$LAST_ERROR_CODE}"

    # Try specific hook first
    if [[ -n "${ERROR_RECOVERY_HOOKS[$code]:-}" ]]; then
        log_info "Attempting recovery for error $code..."
        if ${ERROR_RECOVERY_HOOKS[$code]}; then
            return 0
        fi
    fi

    # Try wildcard hook
    if [[ -n "${ERROR_RECOVERY_HOOKS[*]:-}" ]]; then
        log_info "Attempting generic error recovery..."
        if ${ERROR_RECOVERY_HOOKS[*]}; then
            return 0
        fi
    fi

    return 1
}

#===============================================================================
# ERROR HANDLERS
#===============================================================================

# ERR trap handler
# Usage: Set with: trap 'error_trap_handler' ERR
error_trap_handler() {
    local code=$?
    local cmd="${BASH_COMMAND}"

    # Skip if error code is 0
    [[ $code -eq 0 ]] && return 0

    error_capture "$code" "Command failed: $cmd"

    # Don't print in aggregate mode
    if [[ "$ERROR_AGGREGATE_MODE" != "true" ]]; then
        error_print
    fi

    return "$code"
}

# EXIT trap handler
# Usage: Set with: trap 'error_exit_handler' EXIT
error_exit_handler() {
    local code=$?

    # If we're exiting with error, log final state
    if [[ $code -ne 0 ]] && [[ -n "$LAST_ERROR_MESSAGE" ]]; then
        log_error "Script exited with error code $code"
        if [[ "${DEBUG:-false}" == "true" ]]; then
            error_print >&2
        fi
    fi
}

# Set up comprehensive error handling
# Usage: error_setup_handlers
error_setup_handlers() {
    set -o errexit   # Exit on error
    set -o errtrace  # Inherit ERR trap in functions
    set -o pipefail  # Exit on pipe failure

    trap 'error_trap_handler' ERR
    trap 'error_exit_handler' EXIT

    log_debug "Error handlers installed"
}

# Disable error handling (for sections that need it)
# Usage: error_disable_handlers
error_disable_handlers() {
    set +o errexit
    trap - ERR EXIT
    log_debug "Error handlers disabled"
}

#===============================================================================
# SAFE EXECUTION WRAPPER
#===============================================================================

# Execute command safely with error capture
# Usage: error_safe_exec "description" command [args...]
error_safe_exec() {
    local description="$1"
    shift

    error_push_context "$description"

    local output
    local code=0

    # Capture both stdout and stderr
    if ! output=$("$@" 2>&1); then
        code=$?
        error_capture "$code" "$description failed: $output"
        error_pop_context
        return "$code"
    fi

    error_pop_context
    echo "$output"
    return 0
}

# Execute with custom error message on failure
# Usage: error_exec_or_fail "error_message" command [args...]
error_exec_or_fail() {
    local error_msg="$1"
    shift

    if ! "$@"; then
        local code=$?
        error_fatal "$error_msg" "$code"
    fi
}

#===============================================================================
# ERROR LOG MANAGEMENT
#===============================================================================

# Initialize error log
# Usage: error_log_init
error_log_init() {
    if [[ -n "$ERROR_LOG" ]]; then
        # Create log file if it doesn't exist
        touch "$ERROR_LOG" 2>/dev/null || true

        # Rotate if too large (> 10MB)
        if [[ -f "$ERROR_LOG" ]]; then
            local size
            size=$(stat -f%z "$ERROR_LOG" 2>/dev/null || stat -c%s "$ERROR_LOG" 2>/dev/null || echo 0)
            if [[ $size -gt 10485760 ]]; then
                mv "$ERROR_LOG" "${ERROR_LOG}.old"
                touch "$ERROR_LOG"
                log_debug "Error log rotated"
            fi
        fi
    fi
}

# Clear error log
# Usage: error_log_clear
error_log_clear() {
    if [[ -n "$ERROR_LOG" ]]; then
        > "$ERROR_LOG"
        log_debug "Error log cleared"
    fi
}

# Get recent errors from log
# Usage: error_log_recent [count]
error_log_recent() {
    local count="${1:-10}"

    if [[ -f "$ERROR_LOG" ]]; then
        tail -n "$((count * 10))" "$ERROR_LOG" | grep -A 5 "ERROR CODE" | tail -n "$((count * 6))"
    fi
}

#===============================================================================
# USAGE EXAMPLES
#===============================================================================

# Example 1: Basic error reporting
# error_report "Failed to connect to database" "$E_NETWORK_ERROR"

# Example 2: Fatal error (exits script)
# error_fatal "Critical configuration missing" "$E_CONFIG_ERROR"

# Example 3: Error context tracking
# error_push_context "Installing MySQL exporter"
# ... operations ...
# error_pop_context

# Example 4: Error aggregation (batch mode)
# error_aggregate_start
# for item in "${items[@]}"; do
#     process_item "$item" || error_report "Failed to process $item"
# done
# error_aggregate_finish || exit 1

# Example 5: Safe execution
# error_safe_exec "Downloading package" wget -O /tmp/package.tar.gz "$URL"

# Example 6: Recovery hooks
# recover_from_network_error() {
#     log_info "Attempting to reconnect..."
#     sleep 5
#     return 0
# }
# error_register_recovery "$E_NETWORK_ERROR" "recover_from_network_error"

# Example 7: Full error handling setup
# error_setup_handlers
# error_log_init

#===============================================================================
# INITIALIZATION
#===============================================================================

# Auto-initialize error log
error_log_init
