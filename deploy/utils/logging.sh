#!/usr/bin/env bash
# Logging utilities for deployment scripts
# Usage: source "$(dirname "$0")/../utils/logging.sh"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source colors
source "${SCRIPT_DIR}/colors.sh"

# Default log directory
export LOG_DIR="${LOG_DIR:-/var/log/chom-deploy}"
export LOG_FILE="${LOG_FILE:-${LOG_DIR}/deployment.log}"
export ERROR_LOG_FILE="${ERROR_LOG_FILE:-${LOG_DIR}/deployment-error.log}"

# Create log directory if it doesn't exist
ensure_log_directory() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chown "$(whoami):$(whoami)" "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
    fi
}

# Initialize logging for a deployment
init_deployment_log() {
    local deployment_id="${1:-$(date +%Y%m%d_%H%M%S)}"
    export DEPLOYMENT_ID="$deployment_id"
    export LOG_FILE="${LOG_DIR}/deployment-${deployment_id}.log"
    export ERROR_LOG_FILE="${LOG_DIR}/deployment-${deployment_id}-error.log"

    ensure_log_directory

    echo "=== Deployment started at $(date -Iseconds) ===" > "$LOG_FILE"
    echo "Deployment ID: $DEPLOYMENT_ID" >> "$LOG_FILE"
    echo "User: $(whoami)" >> "$LOG_FILE"
    echo "Hostname: $(hostname)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    print_info "Logging to: $LOG_FILE"
}

# Log message with timestamp
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date -Iseconds)

    ensure_log_directory
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"

    if [[ "$level" == "ERROR" || "$level" == "FATAL" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >> "$ERROR_LOG_FILE"
    fi
}

# Log info message
log_info() {
    log_message "INFO" "$@"
    print_info "$@"
}

# Log success message
log_success() {
    log_message "SUCCESS" "$@"
    print_success "$@"
}

# Log warning message
log_warning() {
    log_message "WARNING" "$@"
    print_warning "$@"
}

# Log error message
log_error() {
    log_message "ERROR" "$@"
    print_error "$@"
}

# Log fatal error and exit
log_fatal() {
    log_message "FATAL" "$@"
    print_error "$@"
    exit 1
}

# Log command execution
log_command() {
    local command="$*"
    log_message "COMMAND" "$command"
}

# Execute command with logging
execute() {
    local command="$*"
    log_command "$command"

    local output
    local exit_code

    if output=$($command 2>&1); then
        exit_code=0
        log_message "OUTPUT" "$output"
    else
        exit_code=$?
        log_error "Command failed with exit code $exit_code: $command"
        log_error "Output: $output"
        return $exit_code
    fi

    return 0
}

# Execute command with logging and exit on failure
execute_or_fail() {
    if ! execute "$@"; then
        log_fatal "Critical command failed: $*"
    fi
}

# Log section header
log_section() {
    local section="$1"
    log_message "SECTION" "=== $section ==="
    print_section "$section"
}

# Log step
log_step() {
    local step="$1"
    log_message "STEP" "$step"
    print_step "$step"
}

# Start timing
start_timer() {
    export TIMER_START=$(date +%s)
}

# End timing and log duration
end_timer() {
    local label="${1:-Operation}"
    local end_time=$(date +%s)
    local duration=$((end_time - TIMER_START))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    log_info "$label completed in ${minutes}m ${seconds}s"
}

# Rotate logs (keep last N log files)
rotate_logs() {
    local keep_count="${1:-10}"

    if [[ -d "$LOG_DIR" ]]; then
        local log_count=$(find "$LOG_DIR" -name "deployment-*.log" | wc -l)

        if [[ $log_count -gt $keep_count ]]; then
            log_info "Rotating logs (keeping last $keep_count)"
            find "$LOG_DIR" -name "deployment-*.log" -type f | \
                sort | \
                head -n -"$keep_count" | \
                xargs rm -f
        fi
    fi
}

# Export functions
export -f ensure_log_directory
export -f init_deployment_log
export -f log_message
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_fatal
export -f log_command
export -f execute
export -f execute_or_fail
export -f log_section
export -f log_step
export -f start_timer
export -f end_timer
export -f rotate_logs
